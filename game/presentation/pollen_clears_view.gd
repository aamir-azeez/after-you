extends RefCounted
## The First chapter clears card on Pollen from play (pollen board 7b): a box
## with the Pollen first clears still pay (the server's prices of the free
## chapters not yet cleared) and how many are cleared, then each free chapter
## with its picture, ticked with what it paid once paid, else its price. Full
## Journey chapters are one sentence, left out on a build that names no Full
## Journey. Every number is the server's; nothing is worked out but the sums.
## Pure drawing: presentation/pollen_play_page.gd gives it the card's column
## (already empty) and the data; it keeps nothing and takes no input.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Parts = preload("res://presentation/pollen_play_parts.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const PollenHistory = preload("res://services/pollen_history.gd")
const CHECK := preload("res://assets/ui/settings/check.svg")

const EARNED_FILL := Color("cfe9df")
const EARNED_INK := Color("1f5b4c")
const TICK := Color("3f8f78")
const RING := Color("a99f86")
const ROW_SIZE := Parts.ROW_SIZE

## Fills `column` from {history (services/pollen_history.gd), full_journey
## (bool: the build names Full Journey), pictures (bool: rows show their
## chapter's picture; off where the card is narrow)}.
static func fill(column: VBoxContainer, model: Dictionary, title_font: Font) -> void:
	Parts.heading(column, PlayerCopy.POLLEN_CLEARS_TITLE, PlayerCopy.POLLEN_CLEARS_NOTE, title_font)
	var clears: Array = model.get("history", {}).get("first_clears", [])
	if not clears.is_empty(): column.add_child(_summary(clears, title_font))
	var pictures := bool(model.get("pictures", true))
	for index in range(clears.size()):
		if index > 0: column.add_child(Parts.rule())
		column.add_child(_row(clears[index], index, pictures))
	var note := PlayerCopy.POLLEN_CLEARS_FULL_JOURNEY + " " + PlayerCopy.POLLEN_CLEARS_HARD if bool(model.get("full_journey", true)) else PlayerCopy.POLLEN_CLEARS_HARD
	var said := Parts.wrapped(note, Parts.NOTE_SIZE, Parts.SOFT_INK)
	said.name = "PollenClearsFoot"
	column.add_child(said)

## What first clears still pay and how many are cleared; once every one is, what they paid.
static func _summary(clears: Array, title_font: Font) -> Control:
	var left := 0
	var waiting := 0
	var earned := 0
	for clear: Dictionary in clears:
		if int(clear.paid) >= 0: earned += int(clear.paid)
		else:
			left += 1
			waiting += int(clear.price)
	var done := clears.size() - left
	# The amount with its grain, its figure in the title type as the bank's count.
	var amount := ShopKit.amount(waiting if left > 0 else earned, Parts.BIG, Parts.INK)
	var figure := amount.get_node("PollenAmountValue") as Label
	figure.add_theme_font_override("font", Parts.title_type(title_font))
	figure.name = "PollenClearsLeft"
	var words := PlayerCopy.POLLEN_CLEARS_ALL_PAID if left == 0 else PlayerCopy.POLLEN_CLEARS_WAITING_ONE if left == 1 else PlayerCopy.POLLEN_CLEARS_WAITING % left
	return Parts.summary("PollenClearsBox", amount, words, done, clears.size(), PlayerCopy.POLLEN_CLEARS_COUNT % [done, clears.size()], "")

## One free chapter: its tick, picture and name, and what it paid or pays.
static func _row(clear: Dictionary, index: int, pictures: bool) -> Control:
	var row := HBoxContainer.new()
	row.name = "PollenClearRow%d" % index
	row.add_theme_constant_override("separation", 12)
	var paid := int(clear.paid) >= 0
	row.add_child(_tick(paid))
	var art := Parts.picture(str(clear.level_id)) if pictures else null
	if art != null: row.add_child(art)
	var title := Parts.text(PollenHistory.chapter_title(str(clear.level_id)), ROW_SIZE, Parts.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(title)
	if paid:
		var pill := PanelContainer.new()
		pill.name = "PollenClearEarned"
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pill.add_theme_stylebox_override("panel", ControlTheme.padded(ControlTheme.rounded(EARNED_FILL, 8), 8.0, 2.0))
		pill.add_child(Parts.text(PlayerCopy.POLLEN_CLEAR_EARNED % PollenMoney.grouped(int(clear.paid)), Parts.NOTE_SIZE, EARNED_INK))
		row.add_child(pill)
	else:
		var price := ShopKit.amount(int(clear.price), ROW_SIZE, Parts.INK)
		price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(price)
	return row

## A round tick, filled once the clear is paid.
static func _tick(done: bool) -> Control:
	var ring := PanelContainer.new()
	ring.custom_minimum_size = Vector2(24, 24)
	ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := ControlTheme.rounded(TICK if done else Color.TRANSPARENT, 12, TICK if done else RING)
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
