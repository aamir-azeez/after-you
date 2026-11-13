extends Control
## The Wardrobe page as Pollen board 5b draws it ("Wardrobe, always open"):
## - the header: the coral back square, "Wardrobe" over its note, and the
##   balance chip with the grain (kit/pollen_chip.gd): its balance opens the
##   Pollen page, and its +, only while bundles sell, the Pollen store;
## - on the left, the big pip wearing what is picked, with the "Your pip" /
##   "As your friend sees you" switch (the friend's room shows your pip in mint),
##   "Drag to turn your pip." and one main button: Buy for [grain] N, Wear,
##   or Take off;
## - on the right, the All items and Owned tabs with "Every item stays in the
##   shop", the "Featured this week" shelf in its own tinted panel, the slot
##   chips (Hat, Body, Leaf: only slots that have something to show), and the
##   item cards in their tier frames (kit/tier_frame.gd) with the tier mark and
##   word, and the price with its grain, or Yours and Wearing.
##   An earned item has the Earned frame and a "Not for sale" lock chip. All
##   items lists every earned item the server offers, owned or not: one not
##   owned has no price and no Buy, and picking it says how it is earned.
##   While the shop has anything the player does not own, every slot of Owned
##   ends with a "Get more" card, an item card's size: the empty Wardrobe's bare
##   hanger in a dashed card (presentation/empty_state_art.gd, drawn once, no
##   pip). It asks for All items on its slot (more_chosen).
## Every item stays in the shop: nothing here counts down, runs out or leaves.
##
## Without the shop (a build that sells nothing, as iOS, or a server with
## POLLEN_SHOP off) the same frame shows the Owned tab and what the player
## owns: no price, no Buy, no shelf, no + and no sale wording. All items shows
## too while an earned item the player does not own is offered (model
## all_items); its card keeps the Earned frame and word with their lock mark.
##
## A view only. presentation/wardrobe_flow.gd builds the model and answers the
## signals; render(model) redraws from it. The model:
##   balance (int, -1 while unknown), status, retry, shop (bool), all_items
##   (bool: the All items tab shows; the shop's value when left out), bundles (bool:
##   the chip's +), tab ("all" or "owned"), kind (the slot chip picked), kinds
##   (slots that have something in this tab), selected (id or ""), view ("you"
##   or "friend"), preview (the look the big pip wears), featured (ids), and
##   more (bool: Owned ends with Get more), buy_offline (bool: Buy greys with a
##   line saying it needs a connection), note (a line shown while no status is:
##   the offline note), items: Array of {id, name, tier,
##   slot, price, owned, worn, locked,
##   unlock_name, sold, earn (how an earned item is earned, else "")}, in shop order.
## The Orchard (Fruits board 4a): while Fruits show (model `orchard`) the slot
## chips end with the Orchard chip (the Fruit and "Orchard"), which asks for the
## "orchard" tab; on it the right panel is the plum Orchard
## (presentation/wardrobe_orchard.gd) in place of the cream shop, and a picked
## Orchard item's button is plum: "Buy for [Fruit] 100". Each item has its
## `currency`; in_tab() says which tab lists it (All items is Pollen only), and
## `sets` holds the Orchard's sets, picked like an item. `fruits_blocked`: the
## Fruit balance is below 0, so a Fruit Buy greys and says why.
## Cards draw still pips (kit/pip_avatar.gd still mode), so a long list shares
## the one offscreen renderer; only the big pip is live, and it is made again
## only when the switch changes its colour.
const ButtonTicks = preload("res://presentation/button_ticks.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const PageMargin = preload("res://presentation/kit/page_margin.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const PipAvatar = preload("res://presentation/kit/pip_avatar.gd")
const PipOutfit = preload("res://presentation/pip_outfit.gd")
const PollenChip = preload("res://presentation/kit/pollen_chip.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const TierFrame = preload("res://presentation/kit/tier_frame.gd")
const SpiritLook = preload("res://presentation/spirit_look.gd")
const EmptyArt = preload("res://presentation/empty_state_art.gd")
const Outfit = preload("res://services/outfit.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const Orchard = preload("res://presentation/wardrobe_orchard.gd")
const Sheets = preload("res://presentation/wardrobe_sheets.gd")
const OrchardSurface = preload("res://presentation/kit/orchard_surface.gd")
const CurrencyMark = preload("res://presentation/kit/currency_mark.gd")
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
## An item card's inner margin and picture height.
const CARD_PAD := 10
const CARD_PICTURE := 72
const SHELF_CARD_SIZE := Vector2(150, 150)
const CARD_PIP := Vector2(56, 70)
const SHELF_PIP := Vector2(50, 62)
const BIG_PIP := Vector2(230, 270)

signal back_pressed
signal tab_chosen(tab: String)
signal kind_chosen(kind: String)
signal view_chosen(view: String)
signal item_chosen(id: String)
## The Owned tab's Get more card: All items on slot `kind` ("" for every slot).
signal more_chosen(kind: String)
signal action_pressed(id: String)
signal retry_pressed
signal plus_pressed
## The balance on the chip: the Pollen page.
signal pollen_pressed
## The chip's Fruit half: the Fruits page.
signal fruits_pressed

var back_button: Button
var action_button: Button
var preview: Control
## The balance chip (kit/pollen_chip.gd), made again only when what it shows changes.
var chip: Control
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
## The scroll's list, and the empty list's drawing in it while there is one.
var _list: VBoxContainer
## The cream shop panel, and the Orchard shown in its place on the Orchard tab.
var _shop: Control
var _orchard: Orchard
var _empty: Control
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
	var margin := PageMargin.new(28, 20)
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
	_shop = _shop_panel()
	body.add_child(_shop)
	_orchard = Orchard.new()
	_orchard.reduced = _reduced
	_orchard.visible = false
	_orchard.item_chosen.connect(func(id: String) -> void: item_chosen.emit(id))
	_orchard.kind_chosen.connect(func(kind: String) -> void: kind_chosen.emit(kind))
	body.add_child(_orchard)

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
	# The soft round floor the big pip stands on (board 5b), drawn once behind it.
	var floor := Floor.new()
	floor.custom_minimum_size = BIG_PIP
	_pip_box.add_child(floor)
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
	preview.place = PipOutfit.WARDROBE
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
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)
	_list.add_child(_shelf_panel())
	_kinds = HBoxContainer.new()
	_kinds.name = "WardrobeKinds"
	_kinds.add_theme_constant_override("separation", 8)
	_list.add_child(_kinds)
	_grid = HFlowContainer.new()
	_grid.name = "WardrobeItems"
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_list.add_child(_grid)
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
	_show_chip(int(model.get("balance", -1)), bool(model.get("balance_known", int(model.get("balance", -1)) >= 0)), bool(model.get("bundles", false)), model.get("fruits", []))
	var status := str(model.get("status", ""))
	var line := status if not status.is_empty() else str(model.get("note", ""))
	_status.text = line
	_status.visible = not line.is_empty()
	_retry.visible = bool(model.get("retry", false))
	var shop := bool(model.get("shop", PollenSurfaces.shared().shop_visible()))
	var tab := str(model.get("tab", "all"))
	_tabs.all.visible = bool(model.get("all_items", shop))
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
	for entry: Dictionary in model.get("items", []) + model.get("sets", []): by_id[entry.id] = entry
	var orchard := tab == "orchard"
	_shop.visible = not orchard
	_orchard.visible = orchard
	if orchard: _orchard.render(_model, line)
	var featured: Array = (model.get("featured", []) as Array).filter(func(id: String) -> bool: return by_id.has(id)).map(func(id: String) -> Dictionary: return by_id[id])
	var kind := str(model.get("kind", ""))
	var shown: Array = (model.get("items", []) as Array).filter(func(entry: Dictionary) -> bool: return in_tab(entry, tab) and (kind.is_empty() or Catalog.chip(entry.slot) == kind))
	# An empty list shows the drawing (empty_state.gd) with its case's line:
	# nothing owned, nothing in the shop, or no shop. Never while the status
	# line says loading or offline.
	var empty := ""
	if shown.is_empty() and status.is_empty():
		empty = PlayerCopy.WARDROBE_NOTHING_EARNED if not shop else (PlayerCopy.WARDROBE_NOTHING_IN_SHOP if tab == "all" else PlayerCopy.WARDROBE_NOTHING_OWNED)
	# Owned ends with Get more when the flow says so (model.more), after at least one owned card.
	var more := bool(model.get("more", false)) and not shown.is_empty()
	var key := var_to_str([featured, shown, model.get("kinds", []), kind, shop, empty, more, model.get("orchard", false)])
	if key != _cards_key and not orchard:
		_cards_key = key
		_fill(_featured, featured, true)
		_fill_kinds(model.get("kinds", []), kind, bool(model.get("orchard", false)))
		_fill(_grid, shown, false)
		if more: _grid.add_child(_more_card(kind))
		_show_empty(empty)
	else:
		_restyle(_featured)
		_restyle(_grid)
	_shelf.visible = shop and tab == "all" and not featured.is_empty()
	_show_selected(by_id.get(str(model.get("selected", "")), {}), shop, bool(model.get("buy_offline", false)), bool(model.get("fruits_blocked", false)))
	if preview.has_method("wear"): preview.wear(model.get("preview", {}))

## Whether `entry` lists in `tab`: the Orchard lists what is sold for Fruits,
## Owned what is owned (either currency), All items the rest (Pollen and earned).
static func in_tab(entry: Dictionary, tab: String) -> bool:
	var fruit: bool = entry.get("currency", "pollen") == "fruits"
	if tab == "orchard": return fruit
	if tab == "owned": return bool(entry.get("owned", false))
	return not fruit

## The empty list's drawing with `line` under it, or none when `line` is empty.
func _show_empty(line: String) -> void:
	if is_instance_valid(_empty):
		_list.remove_child(_empty)
		_empty.queue_free()
	_empty = null
	_grid.visible = line.is_empty()
	if line.is_empty(): return
	_empty = ThemeRules.empty_state(_list, "wardrobe", "", line)

## The chip for `balance`, with its plus while bundles sell and its Fruit half
## while Fruits show (`fruits`, kit/pollen_chip.gd fruits_for); none until the server has said.
func _show_chip(balance: int, known: bool, plus: bool, fruits: Array = []) -> void:
	var wanted := [balance, known, plus, fruits]
	if wanted == _chip_shown: return
	_chip_shown = wanted
	if is_instance_valid(chip):
		_chip_box.remove_child(chip)
		chip.queue_free()
	chip = null
	if not known: return
	chip = PollenChip.make(balance, plus, fruits)
	chip.amount_pressed.connect(func() -> void: pollen_pressed.emit())
	chip.fruits_pressed.connect(func() -> void: fruits_pressed.emit())
	chip.plus_pressed.connect(func() -> void: plus_pressed.emit())
	_chip_box.add_child(chip)

func _show_selected(entry: Dictionary, shop: bool, buy_offline: bool = false, fruits_blocked: bool = false) -> void:
	action_button.visible = not entry.is_empty()
	_name.text = str(entry.get("name", ""))
	_hint.visible = true
	var fruit: bool = entry.get("currency", "") == "fruits"
	var word := Orchard.tier_word(str(entry.get("tier", ""))) if fruit else ""
	_hint.text = PlayerCopy.ORCHARD_HINT % word.to_lower() if not word.is_empty() else PlayerCopy.WARDROBE_DRAG
	_note.text = ""
	_note.visible = false
	if entry.is_empty(): return
	action_button.disabled = false
	# Wear and Take off sound their own chime; a press toward Buy ticks.
	ButtonTicks.quiet(action_button, bool(entry.owned))
	var label := ""
	if bool(entry.owned) and bool(entry.get("set", false)):
		# A set is worn piece by piece.
		action_button.visible = false
		return
	if bool(entry.owned):
		label = PlayerCopy.WARDROBE_TAKE_OFF if bool(entry.worn) else PlayerCopy.WARDROBE_WEAR
	elif not bool(entry.sold) or not shop:
		action_button.visible = false
		if entry.tier == "earned" and not str(entry.get("earn", "")).is_empty(): _set_note(str(entry.earn))
	elif bool(entry.locked):
		action_button.disabled = true
		_set_note(PlayerCopy.WARDROBE_LOCKED % str(entry.unlock_name))
	elif buy_offline:
		# Buying needs the server: the button keeps its price, greyed, and says why.
		action_button.disabled = true
		_set_note(PlayerCopy.WARDROBE_CONNECT_TO_BUY)
	elif fruit and fruits_blocked:
		# Spending Fruits waits while a refund left them below zero.
		action_button.disabled = true
		_set_note(PlayerCopy.ORCHARD_ERRORS.fruits_blocked)
	action_button.text = ""
	action_button.tooltip_text = ""
	if not label.is_empty():
		ShopKit.set_button_content(action_button, ShopKit.text(label, 22, INK, ShopKit.bold_font()))
		action_button.accessibility_name = label
		_cream(action_button)
		return
	if not action_button.visible: return
	# Buy for [grain] 20,000 (or [Fruit] 100 on plum), all inside the one button.
	var price := int(entry.price)
	ShopKit.set_button_content(action_button, Sheets.buy_words(price, 22, OrchardSurface.TEXT if fruit else INK, str(entry.get("currency", ""))))
	action_button.accessibility_name = PlayerCopy.WARDROBE_BUY % PollenMoney.grouped(price)
	if fruit: OrchardSurface.plum_button(action_button)
	else: _cream(action_button)

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
		if not card is Button or not card.has_meta("item_id"): continue
		var id := str(card.get_meta("item_id", ""))
		var tier := str(card.get_meta("tier", "common"))
		var on := id == picked
		(card as Button).set_pressed_no_signal(on)
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			card.add_theme_stylebox_override(state, TierFrame.style(tier, 16, on or state in ["pressed", "hover_pressed"]))

func _fill_kinds(kinds: Array, picked: String, orchard: bool = false) -> void:
	for child: Node in _kinds.get_children():
		_kinds.remove_child(child)
		child.queue_free()
	_kinds.visible = kinds.size() + (1 if orchard else 0) > 1
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
	if orchard: _kinds.add_child(_orchard_chip())

## The slot chips' last one while Fruits show: the Fruit and "Orchard", opening the Orchard.
func _orchard_chip() -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.add_child(CurrencyMark.beside("fruits", 15))
	row.add_child(ShopKit.text(PlayerCopy.ORCHARD_TAB, 15, INK))
	var button := ShopKit.content_button(row, 40)
	button.name = "WardrobeKind_orchard"
	button.accessibility_name = PlayerCopy.ORCHARD_TAB
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var fill := CHIP if state in ["normal", "focus"] else CHIP.darkened(0.06)
		button.add_theme_stylebox_override(state, ThemeRules.padded(ThemeRules.rounded(fill, 12), 14, 6))
	button.pressed.connect(func() -> void: tab_chosen.emit("orchard"))
	return button

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
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 8 if small else CARD_PAD)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	margin.add_child(column)
	var picture := PanelContainer.new()
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.add_theme_stylebox_override("panel", ThemeRules.rounded(PICTURE, 12))
	picture.custom_minimum_size.y = 64 if small else CARD_PICTURE
	column.add_child(picture)
	var pip := PipAvatar.new(_reduced, SpiritLook.PEACH, SHELF_PIP if small else CARD_PIP, true)
	pip.place = PipOutfit.WARDROBE
	pip.outfit = Outfit.of(str(entry.id))
	pip.animate_moving = true
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
	# An Orchard item (in Owned) has its Orchard word; the Pollen tiers their mark and word.
	if not small and entry.get("currency", "") == "fruits": title_row.add_child(ShopKit.text(Orchard.tier_word(tier).to_upper(), 11, INK_SOFT, ShopKit.bold_font()))
	elif not small: title_row.add_child(TierFrame.label(tier, 11, ShopKit.bold_font()))
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
		bottom.add_child(ShopKit.amount(int(entry.price), 13 if small else 15, INK, "", "", str(entry.get("currency", ""))))
	return card

## The Owned tab's Get more card for slot `kind`: an item card's size, the
## bare hanger where the pip would be, and the words under it.
func _more_card(kind: String) -> Button:
	var card := Button.new()
	card.name = "WardrobeGetMore"
	card.custom_minimum_size = CARD_SIZE
	card.accessibility_name = PlayerCopy.WARDROBE_GET_MORE
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		card.add_theme_stylebox_override(state, ThemeRules.rounded(Color.TRANSPARENT if state in ["normal", "focus"] else Color(CHIP, 0.6), 16))
	card.pressed.connect(func() -> void: more_chosen.emit(kind))
	var art := MoreArt.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(art)
	var words := ShopKit.text(PlayerCopy.WARDROBE_GET_MORE, 15, INK_SOFT, ShopKit.bold_font())
	words.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	words.offset_top = CARD_PAD + CARD_PICTURE
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(words)
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

## The flat oval under the big pip's feet.
class Floor extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var centre := Vector2(size.x * 0.5, size.y * 0.9)
		draw_set_transform(centre, 0.0, Vector2(1.0, 0.24))
		draw_circle(Vector2.ZERO, size.x * 0.48, Color("24524b"), true, -1.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## The Get more card's drawing: a dashed card and picture with the empty
## Wardrobe's bare hanger in it (empty_state_art.gd "wardrobe"). It draws in
## _draw only, so it costs nothing on idle frames.
class MoreArt extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var spec: Dictionary = EmptyArt.CARDS.wardrobe
		var picture := Rect2(CARD_PAD, CARD_PAD, size.x - CARD_PAD * 2, CARD_PICTURE)
		EmptyArt.ghost_outline(self, Rect2(Vector2.ONE, size - Vector2(2, 2)), spec.radius, picture, spec.slot_radius, spec.ink)
		EmptyArt.scene(self, "wardrobe", picture)

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
