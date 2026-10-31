extends Control
## Pollen from play (pollen board 7b): what play has earned and what it still
## can. A header with the coral back square, the title and the balance chip;
## then two cards, each drawn by its own view:
## - Turns with friends (presentation/pollen_turns_view.gd): the turn bank and
##   the newest turns;
## - First chapter clears (presentation/pollen_clears_view.gd): what first
##   clears still pay, and each free chapter, paid or not.
## While the page lists purchases (a Google Play build where bundles sell or
## were bought: pollen board 1's "Pollen and purchases"), a Purchases card comes
## first (presentation/pollen_purchases_view.gd) and the title says so; with
## three cards the rows leave out their chapter pictures, which need the width.
## presentation/pollen_play_flow.gd reads the data and calls render(); this
## script only draws it. Each card scrolls on its own. No timers, no countdown.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const Parts = preload("res://presentation/pollen_play_parts.gd")
const TurnsView = preload("res://presentation/pollen_turns_view.gd")
const ClearsView = preload("res://presentation/pollen_clears_view.gd")
const PurchasesView = preload("res://presentation/pollen_purchases_view.gd")
const BACK_ICON = preload("res://assets/ui/social/arrow-left.svg")

const CARD := Color("f3efdf")
## Room kept for a card's scroll bar while it shows, so a long list's amounts stay clear of it.
const GUTTER := 12

signal back_pressed
signal retry_pressed

var back_button: Button
var title_font: Font
var _chip_slot: HBoxContainer
var _title_label: Label
var _turns: VBoxContainer
var _clears: VBoxContainer
## The Purchases card's column, and the card, hidden until the page lists purchases.
var _purchases: VBoxContainer
var _purchases_card: Control

func _init(heading_font: Font = null) -> void:
	title_font = heading_font
	name = "PollenPlayPage"
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
	outer.add_theme_constant_override("separation", 16)
	margin.add_child(outer)
	outer.add_child(_header())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)
	_purchases = _card(body, "PollenPurchasesCard", false)
	_purchases_card = body.get_node("PollenPurchasesCard")
	_purchases_card.visible = false
	_turns = _card(body, "PollenTurnsCard")
	_clears = _card(body, "PollenClearsCard")

func _header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	# The coral back square the board draws, as on the Pollen store.
	back_button = Button.new()
	back_button.name = "PollenPlayBack"
	back_button.custom_minimum_size = Vector2(56, 56)
	back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back_button.tooltip_text = PlayerCopy.POLLEN_PLAY_BACK
	back_button.accessibility_name = PlayerCopy.POLLEN_PLAY_BACK
	back_button.expand_icon = true
	ControlTheme.danger(back_button, BACK_ICON)
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	header.add_child(back_button)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.add_theme_constant_override("separation", 0)
	header.add_child(titles)
	_title_label = Parts.text(PlayerCopy.POLLEN_PLAY_TITLE, 34, UiTokens.CREAM)
	_title_label.name = "PollenPlayTitle"
	if title_font != null: _title_label.add_theme_font_override("font", title_font)
	titles.add_child(_title_label)
	titles.add_child(Parts.text(PlayerCopy.POLLEN_PLAY_SUBTITLE, 17, UiTokens.MUTED))
	_chip_slot = HBoxContainer.new()
	_chip_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_chip_slot)
	return header

## A card's column; with `gutter`, room for the scroll bar while it shows
## (the Purchases card keeps that room in its own rows).
func _card(parent: Control, card_name: String, gutter: bool = true) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = card_name
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", ControlTheme.padded(ControlTheme.rounded(CARD, 18), 22.0, 18.0))
	parent.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	# Fills the card's height, so the room under a short list is the card's own (presentation/pollen_play_spare.gd).
	var inset := MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(inset)
	if gutter:
		var bar := scroll.get_v_scroll_bar()
		bar.visibility_changed.connect(func() -> void: inset.add_theme_constant_override("margin_right", GUTTER if bar.visible else 0))
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	inset.add_child(column)
	return column

## Draws `model` from the flow: {chip (kit/pollen_chip.gd, or null before a
## balance is known), full_journey, status ("" when the history is in), retry,
## history (services/pollen_history.gd), purchases (bool: the Purchases card
## shows, with the history's purchases), spent_usd_cents (-1: no total shows),
## money (bool: the card shows money at all, only for a store selling in US dollars)}.
func render(model: Dictionary) -> void:
	var chip: Variant = model.get("chip")
	for child: Node in _chip_slot.get_children():
		if child == chip: continue
		_chip_slot.remove_child(child)
		child.queue_free()
	if chip is Control and (chip as Control).get_parent() != _chip_slot: _chip_slot.add_child(chip)
	for column: VBoxContainer in [_purchases, _turns, _clears]:
		for child: Node in column.get_children():
			column.remove_child(child)
			child.queue_free()
	var purchases := bool(model.get("purchases", false))
	var status := str(model.get("status", ""))
	var history: Dictionary = model.get("history", {})
	_title_label.text = PlayerCopy.SETTINGS_POLLEN_PURCHASES if purchases else PlayerCopy.POLLEN_PLAY_TITLE
	_purchases_card.visible = purchases
	if purchases: PurchasesView.fill(_purchases, {"loading": not status.is_empty(), "lines": history.get("purchases", []), "spent_usd_cents": int(model.get("spent_usd_cents", -1)), "money": bool(model.get("money", false))}, title_font)
	if not status.is_empty():
		Parts.heading(_turns, PlayerCopy.POLLEN_TURNS_TITLE, PlayerCopy.POLLEN_TURNS_NOTE, title_font)
		Parts.heading(_clears, PlayerCopy.POLLEN_CLEARS_TITLE, PlayerCopy.POLLEN_CLEARS_NOTE, title_font)
		var line := Parts.wrapped(status, Parts.ROW_SIZE, Parts.SOFT_INK)
		line.name = "PollenPlayStatus"
		_turns.add_child(line)
		if bool(model.get("retry", false)):
			var retry := Button.new()
			retry.name = "PollenPlayRetry"
			retry.text = PlayerCopy.POLLEN_PLAY_RETRY
			retry.custom_minimum_size = Vector2(0, 50)
			retry.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			retry.pressed.connect(func() -> void: retry_pressed.emit())
			_turns.add_child(retry)
		return
	var cards := {"history": history, "full_journey": bool(model.get("full_journey", true)), "pictures": not purchases}
	TurnsView.fill(_turns, cards, title_font)
	ClearsView.fill(_clears, cards, title_font)
