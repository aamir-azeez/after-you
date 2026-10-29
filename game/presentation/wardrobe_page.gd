extends Control
## The Wardrobe page (board 5b): the player's own pip on the left wearing what
## is picked, and on the right "Featured this week" over every item, filtered
## by All items or Owned. Every item stays in the shop: nothing here counts
## down, runs out or leaves.
##
## A view only. presentation/wardrobe_flow.gd builds the model and answers the
## signals; render(model) redraws everything from it. The model:
##   balance (int, -1 while unknown), status (String: a loading or offline line,
##   or ""), retry (bool: show Try again), shop (bool: the build shows the
##   shop; without it the tabs are hidden and only owned items come in), tab
##   ("all" or "owned"), selected (id or ""), preview (the look the big pip wears), featured (Array of ids), and
##   items: Array of {id, name, tier, slot, price, owned, worn, locked,
##   unlock_name, sold}, in shop order.
## Item cards draw still pips (kit/pip_avatar.gd still mode), so a long list
## shares the one offscreen renderer; only the big pip is live.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const PipAvatar = preload("res://presentation/kit/pip_avatar.gd")
const PollenMark = preload("res://presentation/kit/pollen_mark.gd")
## The balance's font size; its Pollen mark is sized from it.
const BALANCE_FONT := 22
const Outfit = preload("res://services/outfit.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")

const CREAM := Color("eceddb")
const MUTED := Color("afc6be")
const PANEL := Color("173f39")
const CARD := Color("f3efdf")
const INK := Color("1d3230")
## Tier frames, softest to brightest (board 5b).
const TIER_COLORS := {"common": Color("c9d8c4"), "uncommon": Color("9fcfae"), "rare": Color("aab8f0"), "epic": Color("e2b3e8"), "special": Color("f2cf86"), "earned": Color("f2cf86")}
const CARD_SIZE := Vector2(150, 150)
const CARD_PIP := Vector2(64, 84)

signal back_pressed
signal tab_chosen(tab: String)
signal item_chosen(id: String)
signal action_pressed(id: String)
signal retry_pressed

var back_button: Button
var action_button: Button
var preview: Control
var _balance: Label
var _balance_mark: Control
var _status: Label
var _retry: Button
var _name: Label
var _facts: Label
var _note: Label
var _tabs := {}
var _tab_row: HBoxContainer
var _featured: HFlowContainer
var _featured_title: Label
var _grid: HFlowContainer
var _reduced := false
var _model: Dictionary = {}

func _init(reduced: bool = false) -> void:
	_reduced = reduced
	name = "WardrobePage"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.10, 0.10, 0.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SafeArea.bleed(shade)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	margin.add_child(outer)
	outer.add_child(_header())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)
	body.add_child(_pip_panel())
	body.add_child(_shop_panel())

func _header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	back_button = Button.new()
	back_button.name = "WardrobeBack"
	back_button.text = PlayerCopy.WARDROBE_BACK
	back_button.custom_minimum_size = Vector2(0, 54)
	ThemeRules.secondary(back_button)
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	header.add_child(back_button)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(_text(PlayerCopy.WARDROBE_TITLE, 34, CREAM))
	titles.add_child(_text(PlayerCopy.WARDROBE_NOTE, 16, MUTED))
	header.add_child(titles)
	# The Pollen mark (kit/pollen_mark.gd) sits before the balance while there is one.
	_balance_mark = PollenMark.beside(BALANCE_FONT)
	_balance_mark.visible = false
	header.add_child(_balance_mark)
	_balance = _text("", BALANCE_FONT, CREAM)
	_balance.name = "WardrobeBalance"
	_balance.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_balance)
	return header

func _pip_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 300
	panel.add_theme_stylebox_override("panel", ThemeRules.padded(ThemeRules.rounded(PANEL, 22), 18, 16))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(column)
	preview = PipAvatar.new(_reduced, PipAvatar.PEACH, Vector2(200, 260))
	preview.name = "WardrobePip"
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(preview)
	_name = _text("", 24, CREAM)
	_name.name = "WardrobeItemName"
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_name)
	_facts = _text("", 16, MUTED)
	_facts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_facts)
	_note = _text("", 16, MUTED)
	_note.name = "WardrobeItemNote"
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = 260
	column.add_child(_note)
	action_button = Button.new()
	action_button.name = "WardrobeAction"
	action_button.custom_minimum_size = Vector2(0, 54)
	action_button.pressed.connect(func() -> void: if not str(_model.get("selected", "")).is_empty(): action_pressed.emit(str(_model.selected)))
	column.add_child(action_button)
	return panel

func _shop_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", ThemeRules.padded(ThemeRules.rounded(CARD, 22), 18, 14))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var tabs := HBoxContainer.new()
	tabs.name = "WardrobeTabs"
	tabs.add_theme_constant_override("separation", 8)
	_tab_row = tabs
	for tab: Array in [["all", PlayerCopy.WARDROBE_ALL], ["owned", PlayerCopy.WARDROBE_OWNED]]:
		var button := Button.new()
		button.name = "WardrobeTab_" + tab[0]
		button.text = tab[1]
		button.custom_minimum_size = Vector2(0, 44)
		button.pressed.connect(func() -> void: tab_chosen.emit(tab[0]))
		tabs.add_child(button)
		_tabs[tab[0]] = button
	column.add_child(tabs)
	_status = _text("", 18, INK)
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
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ThemeRules.touch_scroll(scroll)
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	_featured_title = _text(PlayerCopy.WARDROBE_FEATURED, 20, INK)
	list.add_child(_featured_title)
	_featured = HFlowContainer.new()
	_featured.name = "WardrobeFeatured"
	_featured.add_theme_constant_override("h_separation", 10)
	_featured.add_theme_constant_override("v_separation", 10)
	list.add_child(_featured)
	_grid = HFlowContainer.new()
	_grid.name = "WardrobeItems"
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	list.add_child(_grid)
	return panel

## Redraws the page from the flow's model.
func render(model: Dictionary) -> void:
	_model = model.duplicate(true)
	var balance := int(model.get("balance", -1))
	_balance.text = PlayerCopy.WARDROBE_BALANCE % PollenMoney.grouped(balance) if balance >= 0 else ""
	_balance_mark.visible = balance >= 0
	var status := str(model.get("status", ""))
	_status.text = status
	_status.visible = not status.is_empty()
	_retry.visible = bool(model.get("retry", false))
	var shop := bool(model.get("shop", PollenSurfaces.shared().shop_visible()))
	_tab_row.visible = shop
	var tab := str(model.get("tab", "all"))
	for key: String in _tabs:
		if key == tab: ThemeRules.selected_tab(_tabs[key])
		else: ThemeRules.plain_tab(_tabs[key])
	var by_id := {}
	for entry: Dictionary in model.get("items", []): by_id[entry.id] = entry
	_fill(_featured, (model.get("featured", []) as Array).filter(func(id: String) -> bool: return by_id.has(id)).map(func(id: String) -> Dictionary: return by_id[id]))
	_featured_title.visible = tab == "all" and _featured.get_child_count() > 0
	_featured.visible = _featured_title.visible
	var shown: Array = (model.get("items", []) as Array).filter(func(entry: Dictionary) -> bool: return tab == "all" or bool(entry.owned))
	_fill(_grid, shown)
	if tab == "owned" and shown.is_empty() and status.is_empty():
		_status.text = PlayerCopy.WARDROBE_NOTHING_OWNED if shop else PlayerCopy.WARDROBE_NOTHING_EARNED
		_status.visible = true
	_show_selected(by_id.get(str(model.get("selected", "")), {}))
	if preview.has_method("wear"): preview.wear(model.get("preview", {}))

func _show_selected(entry: Dictionary) -> void:
	action_button.visible = not entry.is_empty()
	_name.text = str(entry.get("name", ""))
	_facts.text = "" if entry.is_empty() else PlayerCopy.WARDROBE_FACTS % [str(PlayerCopy.WARDROBE_SLOTS.get(entry.slot, "")), str(PlayerCopy.WARDROBE_TIERS.get(entry.tier, ""))]
	_note.text = ""
	if entry.is_empty(): return
	action_button.disabled = false
	if bool(entry.owned):
		action_button.text = PlayerCopy.WARDROBE_TAKE_OFF if bool(entry.worn) else PlayerCopy.WARDROBE_WEAR
	elif not bool(entry.sold):
		action_button.visible = false
		_note.text = PlayerCopy.WARDROBE_EARNED if entry.tier == "earned" else PlayerCopy.WARDROBE_ERRORS.not_for_sale
	elif bool(entry.locked):
		action_button.text = PlayerCopy.WARDROBE_BUY % PollenMoney.grouped(int(entry.price))
		action_button.disabled = true
		_note.text = PlayerCopy.WARDROBE_LOCKED % str(entry.unlock_name)
	else:
		action_button.text = PlayerCopy.WARDROBE_BUY % PollenMoney.grouped(int(entry.price))
		_note.text = PlayerCopy.WARDROBE_ABOUT % PollenMoney.about(int(entry.price))

func _fill(box: HFlowContainer, entries: Array) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for entry: Dictionary in entries: box.add_child(_card(entry))

func _card(entry: Dictionary) -> Control:
	var card := Button.new()
	card.name = "WardrobeCard_" + str(entry.id)
	card.custom_minimum_size = CARD_SIZE
	card.toggle_mode = true
	card.set_pressed_no_signal(str(_model.get("selected", "")) == str(entry.id))
	var frame: Color = TIER_COLORS.get(str(entry.tier), TIER_COLORS.common)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var style := ThemeRules.rounded(CARD.lightened(0.3) if state in ["normal", "focus"] else Color("e6f0e2"), 16, frame)
		style.set_border_width_all(4 if card.button_pressed or state in ["pressed", "hover_pressed"] else 2)
		card.add_theme_stylebox_override(state, style)
	card.pressed.connect(func() -> void: item_chosen.emit(str(entry.id)))
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(column)
	var pip := PipAvatar.new(true, PipAvatar.PEACH, CARD_PIP, true)
	pip.outfit = Outfit.of(str(entry.id))
	pip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(pip)
	var title := _text(str(entry.name), 15, INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)
	var tag := PlayerCopy.WARDROBE_WEARING if bool(entry.worn) else PlayerCopy.WARDROBE_OWNED_TAG if bool(entry.owned) else PlayerCopy.WARDROBE_PRICE % PollenMoney.grouped(int(entry.price)) if bool(entry.sold) else PlayerCopy.WARDROBE_TIERS.earned
	var line := _text(tag, 13, INK.lightened(0.25))
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(line)
	return card

static func _text(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
