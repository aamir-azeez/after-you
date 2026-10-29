extends Control
## Pollen from play (pollen board 7b): what play has earned and what it still
## can. A header with Back, the title and the balance chip; then two cards:
## - Turns with friends: the turn bank (turns left, how full it is, the Monday
##   refill and the cap; when empty, what turns still earn, in the server's
##   numbers), and the newest turns with their bonuses, a lucky bloom, or why
##   one paid a little;
## - First chapter clears: each free chapter, ticked with what it paid once
##   paid, else its price. Full Journey chapters are one sentence, left out on
##   a build that names no Full Journey.
## While the page lists purchases (a Google Play build where bundles sell or
## were bought: pollen board 1's "Pollen and purchases"), a Purchases card comes
## first (presentation/pollen_purchases_view.gd) and the title says so.
## presentation/pollen_play_flow.gd reads the data and calls render(); this
## script only draws it. Each card scrolls on its own. No timers, no countdown.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const PollenMark = preload("res://presentation/kit/pollen_mark.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const PollenHistory = preload("res://services/pollen_history.gd")
const PollenResultLine = preload("res://presentation/pollen_result_line.gd")
const BreakdownView = preload("res://presentation/pollen_breakdown_view.gd")
const Breakdown = preload("res://presentation/pollen_breakdown.gd")
const PurchasesView = preload("res://presentation/pollen_purchases_view.gd")
const CHECK := preload("res://assets/ui/settings/check.svg")

const CARD := Color("f3efdf")
const BOX := Color("fbf8ec")
const INK := Color("1d3230")
const SOFT_INK := Color("4e6660")
const TRACK := Color("ddd6c0")
const FILL := Color("e2b25a")
const EARNED_FILL := Color("cfe9df")
const EARNED_INK := Color("1f5b4c")
const ROW_SIZE := 17

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
	_purchases = _card(body, "PollenPurchasesCard")
	_purchases_card = body.get_node("PollenPurchasesCard")
	_purchases_card.visible = false
	_turns = _card(body, "PollenTurnsCard")
	_clears = _card(body, "PollenClearsCard")

func _header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	back_button = Button.new()
	back_button.name = "PollenPlayBack"
	back_button.text = PlayerCopy.POLLEN_PLAY_BACK
	back_button.custom_minimum_size = Vector2(0, 54)
	ControlTheme.secondary(back_button)
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	header.add_child(back_button)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	header.add_child(titles)
	_title_label = _text(PlayerCopy.POLLEN_PLAY_TITLE, 34, UiTokens.CREAM)
	_title_label.name = "PollenPlayTitle"
	if title_font != null: _title_label.add_theme_font_override("font", title_font)
	titles.add_child(_title_label)
	titles.add_child(_text(PlayerCopy.POLLEN_PLAY_SUBTITLE, 17, UiTokens.MUTED))
	_chip_slot = HBoxContainer.new()
	_chip_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_chip_slot)
	return header

func _card(parent: Control, card_name: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = card_name
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", ControlTheme.padded(ControlTheme.rounded(CARD, 18), 22.0, 18.0))
	parent.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
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
	_title(_turns, PlayerCopy.POLLEN_TURNS_TITLE, PlayerCopy.POLLEN_TURNS_NOTE)
	_title(_clears, PlayerCopy.POLLEN_CLEARS_TITLE, PlayerCopy.POLLEN_CLEARS_NOTE)
	if not status.is_empty():
		var line := _wrapped(status, ROW_SIZE, SOFT_INK)
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
	_bank(history.get("bank", {}))
	_recent(history.get("turns", []))
	_first_clears(history.get("first_clears", []), bool(model.get("full_journey", true)))

func _title(column: VBoxContainer, title: String, note: String) -> void:
	var heading := _text(title, 23, INK)
	if title_font != null: heading.add_theme_font_override("font", title_font)
	column.add_child(heading)
	column.add_child(_wrapped(note, 15, SOFT_INK))

## The turn bank: how many full rate turns are left, how full it is, and its rules.
func _bank(bank: Dictionary) -> void:
	if bank.is_empty(): return
	var box := PanelContainer.new()
	box.name = "PollenBank"
	box.add_theme_stylebox_override("panel", ControlTheme.padded(ControlTheme.rounded(BOX, 14, Color("e4dcc4")), 16.0, 12.0))
	_turns.add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	box.add_child(column)
	var count := HBoxContainer.new()
	count.add_theme_constant_override("separation", 10)
	column.add_child(count)
	var left := int(bank.left)
	var number := _text(str(left), 34, INK)
	number.name = "PollenBankLeft"
	if title_font != null: number.add_theme_font_override("font", title_font)
	count.add_child(number)
	var words := _text(PlayerCopy.POLLEN_BANK_COUNT_ONE if left == 1 else PlayerCopy.POLLEN_BANK_COUNT, ROW_SIZE, INK)
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	count.add_child(words)
	var bar := ProgressBar.new()
	bar.name = "PollenBankBar"
	bar.show_percentage = false
	bar.max_value = maxi(int(bank.cap), 1)
	bar.value = left
	bar.custom_minimum_size.y = 10
	bar.add_theme_stylebox_override("background", ControlTheme.rounded(TRACK, 5))
	bar.add_theme_stylebox_override("fill", ControlTheme.rounded(FILL, 5))
	column.add_child(bar)
	var rules := HBoxContainer.new()
	column.add_child(rules)
	var refill := _text(PlayerCopy.POLLEN_BANK_EMPTY_LINE if left == 0 else PlayerCopy.POLLEN_BANK_REFILL % int(bank.refill), 14, SOFT_INK)
	refill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules.add_child(refill)
	rules.add_child(_text(PlayerCopy.POLLEN_BANK_CAP % int(bank.cap), 14, SOFT_INK))
	if left == 0 and not (bank.tail as Array).is_empty():
		var tail := _wrapped(tail_line(bank), 15, SOFT_INK)
		tail.name = "PollenBankTail"
		_turns.add_child(tail)

## What turns earn once the bank is empty, in the server's numbers.
static func tail_line(bank: Dictionary) -> String:
	var steps := PackedStringArray()
	for step: Dictionary in bank.get("tail", []):
		steps.append((PlayerCopy.POLLEN_TAIL_FIRST if steps.is_empty() else PlayerCopy.POLLEN_TAIL_STEP) % [int(step.pay), int(step.turns)])
	return PlayerCopy.POLLEN_TAIL % [PlayerCopy.POLLEN_TAIL_THEN.join(steps), int(bank.get("refill", 0))]

## The newest turns: where, what added to them, and their Pollen.
func _recent(turns: Array) -> void:
	if turns.is_empty():
		_turns.add_child(_wrapped(PlayerCopy.POLLEN_TURNS_NONE, ROW_SIZE, SOFT_INK))
		return
	for index in range(turns.size()):
		var turn: Dictionary = turns[index]
		if index > 0: _turns.add_child(_rule())
		var row := HBoxContainer.new()
		row.name = "PollenTurnRow%d" % index
		row.add_theme_constant_override("separation", 8)
		_turns.add_child(row)
		var words := VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_theme_constant_override("separation", 0)
		row.add_child(words)
		words.add_child(_wrapped(place(turn), ROW_SIZE, INK))
		var note := turn_note(turn)
		if not note.is_empty(): words.add_child(_wrapped(note, 14, SOFT_INK))
		row.add_child(PollenMark.beside(ROW_SIZE))
		var amount := _text(PollenMoney.grouped(int(turn.amount)), ROW_SIZE, INK)
		amount.name = "PollenAmount"
		amount.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(amount)
		if int(turn.get("bloom", 1)) > 1:
			var tag := BreakdownView.tag(PlayerCopy.POLLEN_BLOOM_SHORT % int(turn.bloom), func() -> Control: return PollenResultLine.Flower.new())
			row.add_child(tag)

## "The Wishing Well, stage 1".
static func place(turn: Dictionary) -> String:
	var title := PollenHistory.chapter_title(str(turn.level_id))
	var stage := PollenHistory.stage_number(str(turn.level_id), str(turn.stage_id))
	return PlayerCopy.POLLEN_TURN_PLACE % [title, stage] if stage > 0 else title

## A turn's small line: its bonuses ("First try · gold pace"), or why it paid a little.
static func turn_note(turn: Dictionary) -> String:
	match str(turn.get("reason", "")):
		"repeat": return PlayerCopy.POLLEN_TURN_REPEAT
		"bank_empty": return PlayerCopy.POLLEN_TURN_BANK_EMPTY
		"late": return PlayerCopy.POLLEN_TURN_LATE
	var names := PackedStringArray()
	for bonus: String in turn.get("bonuses", []):
		var named: String = Breakdown.BONUS_NAMES[bonus]
		names.append(named if names.is_empty() else named.to_lower())
	return PlayerCopy.POLLEN_TURN_BONUS_JOIN.join(names)

## Each free chapter's first clear: ticked with what it paid, or its price.
func _first_clears(clears: Array, full_journey: bool) -> void:
	for index in range(clears.size()):
		var clear: Dictionary = clears[index]
		if index > 0: _clears.add_child(_rule())
		var row := HBoxContainer.new()
		row.name = "PollenClearRow%d" % index
		row.add_theme_constant_override("separation", 10)
		_clears.add_child(row)
		var paid := int(clear.paid) >= 0
		row.add_child(_tick(paid))
		var title := _text(PollenHistory.chapter_title(str(clear.level_id)), ROW_SIZE, INK)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title)
		if paid:
			var pill := PanelContainer.new()
			pill.name = "PollenClearEarned"
			pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pill.add_theme_stylebox_override("panel", ControlTheme.padded(ControlTheme.rounded(EARNED_FILL, 8), 8.0, 2.0))
			pill.add_child(_text(PlayerCopy.POLLEN_CLEAR_EARNED % PollenMoney.grouped(int(clear.paid)), 14, EARNED_INK))
			row.add_child(pill)
		else:
			row.add_child(PollenMark.beside(ROW_SIZE))
			var price := _text(PollenMoney.grouped(int(clear.price)), ROW_SIZE, INK)
			price.name = "PollenAmount"
			row.add_child(price)
	var note := PlayerCopy.POLLEN_CLEARS_HARD if not full_journey else PlayerCopy.POLLEN_CLEARS_FULL_JOURNEY + " " + PlayerCopy.POLLEN_CLEARS_HARD
	_clears.add_child(_wrapped(note, 14, SOFT_INK))

## A round tick, filled once the clear is paid.
func _tick(done: bool) -> Control:
	var ring := PanelContainer.new()
	ring.custom_minimum_size = Vector2(24, 24)
	ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := ControlTheme.rounded(Color("3f8f78") if done else Color.TRANSPARENT, 12, Color("3f8f78") if done else Color("a99f86"))
	style.set_border_width_all(2)
	ring.add_theme_stylebox_override("panel", style)
	if done:
		var check := TextureRect.new()
		check.texture = CHECK
		check.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		check.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		check.custom_minimum_size = Vector2(14, 14)
		check.modulate = Color.WHITE
		ring.add_child(check)
	return ring

func _rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.color = Color(0, 0, 0, 0.08)
	rule.custom_minimum_size.y = 1
	return rule

static func _text(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

static func _wrapped(value: String, size: int, color: Color) -> Label:
	var label := _text(value, size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
